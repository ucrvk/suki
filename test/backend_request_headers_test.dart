import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:suki/services/backend_request_headers.dart';
import 'package:suki/services/maid_image_manifest_service.dart';
import 'package:suki/services/sysbooking_api_service.dart';
import 'package:suki/widgets/proxy_fallback_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    PackageInfo.setMockInitialValues(
      appName: 'suki',
      packageName: 'test.suki',
      version: '2.0.3',
      buildNumber: '1',
      buildSignature: '',
    );
    await BackendRequestHeaders.initialize();
  });

  test('only adds the version header to the backend origin and path', () {
    for (final url in [
      '${BackendRequestHeaders.baseUrl}/manifest.json',
      '${BackendRequestHeaders.baseUrl}/images/test.avif',
      '${BackendRequestHeaders.baseUrl}/pic-proxy/https%3A%2F%2Fexample.com',
    ]) {
      expect(BackendRequestHeaders.forUrl(url), {
        'x-suki-app-version': '2.0.3+1',
      });
    }
    for (final url in [
      'https://uzlzkjuijruqanetagxh.supabase.co/auth/v1/signup',
      'https://uzlzkjuijruqanetagxh.supabase.co/storage/v1/object/public/image.png',
      'https://api.github.com/repos/ucrvk/suki/tags',
      'https://api.wenwen12305.top/suki-evil/images/a.png',
      'https://api.wenwen12305.top.evil/suki/images/a.png',
      'http://api.wenwen12305.top/suki/images/a.png',
    ]) {
      expect(BackendRequestHeaders.forUrl(url), isEmpty, reason: url);
    }
  });

  test(
    'all booking request methods send the app version with existing auth headers',
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
          expect(request.headers['x-suki-app-version'], '2.0.3+1');
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

  test('manifest requests carry the version header', () async {
    await http.runWithClient(
      () async {
        final manifest = await MaidImageManifestService.fetchManifest(
          forceRefresh: true,
        );
        expect(manifest['maid'], 'hash');
      },
      () => MockClient((request) async {
        expect(request.headers['x-suki-app-version'], '2.0.3+1');
        return http.Response('{"maid":"hash"}', 200);
      }),
    );
  });

  testWidgets('backend images carry the app version header', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProxyFallbackImage(
          imageUrl: '${BackendRequestHeaders.baseUrl}/images/test.avif',
          placeholder: (_, _) => const SizedBox(),
          errorWidget: (_, _, _) => const SizedBox(),
        ),
      ),
    );
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.httpHeaders, {'x-suki-app-version': '2.0.3+1'});
    await tester.pumpWidget(const SizedBox());
  });
}
