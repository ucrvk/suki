import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:suki/pages/me_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<Map<String, dynamic>> requests;
  late Map<String, dynamic> payload;
  late int status;

  setUp(() async {
    requests = [];
    status = 200;
    payload = {
      'id': 'test-user',
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'guest@example.com',
      'created_at': '2026-10-28T00:00:00Z',
      'user_metadata': {'username': 'VRC Guest'},
    };
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'suki',
      packageName: 'test.suki',
      version: '2.0.3',
      buildNumber: '1',
      buildSignature: '',
    );
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-key',
      httpClient: MockClient((request) async {
        expect(request.headers.containsKey('x-suki-app-version'), isFalse);
        if (request.url.path == '/auth/v1/signup') {
          requests.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode(payload),
            status,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('[]', 200);
      }),
      authOptions: FlutterAuthClientOptions(
        pkceAsyncStorage: _MemoryStorage(),
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
  });
  tearDown(() => Supabase.instance.dispose());

  Future<void> openForm(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: MePage()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('open-login-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-register-button')));
    await tester.pumpAndSettle();
  }

  Future<void> fill(
    WidgetTester tester, {
    String password = 'safePass123',
    String? confirm,
  }) async {
    await tester.enterText(
      find.byKey(const Key('register-username')),
      ' VRC Guest ',
    );
    await tester.enterText(
      find.byKey(const Key('register-email')),
      ' guest@example.com ',
    );
    await tester.enterText(
      find.byKey(const Key('register-password')),
      password,
    );
    await tester.enterText(
      find.byKey(const Key('register-confirm-password')),
      confirm ?? password,
    );
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('register-submit-button')));
    await tester.pumpAndSettle();
  }

  Future<void> dismissMessages(WidgetTester tester) async {
    ScaffoldMessenger.of(
      tester.element(find.byType(MePage)),
    ).removeCurrentSnackBar();
    await tester.pumpAndSettle();
  }

  testWidgets(
    'validates required fields, password length and confirmation before sending',
    (tester) async {
      await openForm(tester);
      await submit(tester);
      expect(find.text('请输入用户名、邮箱和密码'), findsOneWidget);
      await dismissMessages(tester);
      await fill(tester, password: '12345');
      await submit(tester);
      expect(find.text('密码至少 6 位'), findsOneWidget);
      await dismissMessages(tester);
      await fill(tester, confirm: 'different');
      await submit(tester);
      expect(find.text('两次输入的密码不一致'), findsOneWidget);
      expect(requests, isEmpty);
    },
  );
  testWidgets(
    'sends username metadata and carries email back to login after confirmation signup',
    (tester) async {
      await openForm(tester);
      await fill(tester);
      await submit(tester);
      expect(requests.single['email'], 'guest@example.com');
      expect(requests.single['password'], 'safePass123');
      expect(requests.single['data'], {'username': 'VRC Guest'});
      expect(find.text('注册成功，请到邮箱点击确认链接后再登录'), findsOneWidget);
      expect(find.byKey(const Key('register-email')), findsNothing);
      await dismissMessages(tester);
      await tester.tap(find.byKey(const Key('open-login-button')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('login-email')))
            .controller!
            .text,
        'guest@example.com',
      );
    },
  );
  testWidgets(
    'applies the returned session when no email confirmation is needed',
    (tester) async {
      payload = {
        'access_token': 'test-access',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': payload,
      };
      await openForm(tester);
      await fill(tester);
      await submit(tester);
      expect(find.text('注册成功'), findsOneWidget);
      expect(find.text('VRC Guest'), findsOneWidget);
      expect(find.byKey(const Key('open-register-button')), findsNothing);
    },
  );
  testWidgets('keeps the form editable on failure and supports retry', (
    tester,
  ) async {
    final success = payload;
    payload = {'msg': 'User already registered'};
    status = 422;
    await openForm(tester);
    await fill(tester);
    await submit(tester);
    expect(find.text('该邮箱已注册，请直接登录'), findsOneWidget);
    expect(find.byKey(const Key('register-email')), findsOneWidget);
    await dismissMessages(tester);
    payload = success;
    status = 200;
    await submit(tester);
    expect(requests.length, 2);
    expect(find.text('注册成功，请到邮箱点击确认链接后再登录'), findsOneWidget);
  });
}

class _MemoryStorage extends GotrueAsyncStorage {
  final _values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => _values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }
}
