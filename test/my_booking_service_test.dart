import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:suki/services/my_booking_service.dart';

void main() {
  test('queries only the requested user with authentication', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'publishable-key',
      accessToken: () async => 'user-token',
      httpClient: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/rest/v1/suki_witch_bookings');
        expect(request.url.queryParameters['select'], 'session_id,guests');
        expect(request.url.queryParameters['user_id'], 'eq.current-user');
        expect(request.headers['apikey'], 'publishable-key');
        expect(request.headers['Authorization'], 'Bearer user-token');
        return http.Response(
          '[{"session_id":"actual-session","guests":2}]',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);
    final result = await SupabaseMyBookingService(
      client: client,
    ).fetch('current-user');
    expect(result.single.sessionId, 'actual-session');
    expect(result.single.guests, 2);
  });

  test('cancels actual session through authenticated POST RPC', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'publishable-key',
      accessToken: () async => 'user-token',
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/rest/v1/rpc/cancel_witch_session');
        expect(jsonDecode(request.body), {'p_session_id': 'actual-session'});
        expect(request.headers['Authorization'], 'Bearer user-token');
        return http.Response('', 204, request: request);
      }),
    );
    addTearDown(client.dispose);
    await SupabaseMyBookingService(client: client).cancel('actual-session');
  });
}
