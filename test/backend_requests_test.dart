import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:suki/services/backend_config.dart';
import 'package:suki/services/maid_image_manifest_service.dart';
import 'package:suki/services/sysbooking_api_service.dart';
import 'package:suki/widgets/proxy_fallback_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'booking requests preserve authentication without a version header',
    () async {
      final seen = <String>[];
      await http.runWithClient(
        () async {
          final session = Session.fromJson({
            'access_token': 'access',
            'refresh_token': 'refresh',
            'token_type': 'bearer',
            'user': {
              'id': 'user',
              'aud': 'authenticated',
              'created_at': '2026-10-28T00:00:00Z',
            },
          })!;
          expect(
            await SysbookingApiService.exchangeSessionForBookingToken(
              session: session,
            ),
            'booking',
          );
          await SysbookingApiService.fetchQueueList('booking');
          await SysbookingApiService.updateQueueBooking(
            bookingToken: 'booking',
            bookingId: 'id',
            autoqueue: true,
          );
          await SysbookingApiService.logoutOtherQueueAccounts(
            bookingToken: 'booking',
          );
          await SysbookingApiService.deleteQueueBooking(
            bookingToken: 'booking',
            bookingId: 'id',
          );
          await SysbookingApiService.createQueueBooking(
            bookingToken: 'booking',
            maidId: 'maid',
            timeslot: 21,
            autoqueue: false,
            withFriend: false,
            friendVrcid: '',
          );
        },
        () => MockClient((request) async {
          expect(request.headers.containsKey('x-suki-app-version'), isFalse);
          if (!request.url.path.endsWith('/login')) {
            expect(request.headers['x-booking-token'], 'booking');
          }
          seen.add(request.method);
          if (request.url.path.endsWith('/queuelist')) {
            return http.Response('[]', 200);
          }
          return http.Response(
            jsonEncode({'token': 'booking', 'booking_id': 'id'}),
            200,
          );
        }),
      );
      expect(seen, ['POST', 'GET', 'PUT', 'GET', 'DELETE', 'POST']);
    },
  );

  test('manifest requests do not send a version header', () async {
    await http.runWithClient(
      () async {
        final manifest = await MaidImageManifestService.fetchManifest(
          forceRefresh: true,
        );
        expect(manifest['maid'], 'hash');
      },
      () => MockClient((request) async {
        expect(request.headers.containsKey('x-suki-app-version'), isFalse);
        return http.Response('{"maid":"hash"}', 200);
      }),
    );
  });

  testWidgets('backend images do not send a version header', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProxyFallbackImage(
          imageUrl: '${BackendConfig.baseUrl}/images/test.avif',
          placeholder: (_, _) => const SizedBox(),
          errorWidget: (_, _, _) => const SizedBox(),
        ),
      ),
    );
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.httpHeaders, isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
