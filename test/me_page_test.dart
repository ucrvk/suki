import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suki/pages/me_page.dart';
import 'package:suki/services/account_service.dart';

void main() {
  testWidgets('shows login dialog, validates fields, and signs in', (
    tester,
  ) async {
    final auth = _FakeAuthService();
    final profiles = _FakeProfileService(
      const AccountProfile(username: '纸樱', qqName: '', avatarUrl: ''),
    );
    await tester.pumpWidget(
      _app(MePage(authService: auth, profileService: profiles)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open-login-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-login-button')));
    await tester.pumpAndSettle();
    expect(find.text('邮箱'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);

    await tester.tap(find.byKey(const Key('login-submit-button')));
    await tester.pump();
    expect(find.text('请输入邮箱和密码'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('login-email')),
      'witch@example.com',
    );
    await tester.enterText(find.byKey(const Key('login-password')), 'secret');
    await tester.tap(find.byKey(const Key('login-submit-button')));
    await tester.pumpAndSettle();

    expect(auth.lastEmail, 'witch@example.com');
    expect(auth.lastPassword, 'secret');
    expect(find.text('纸樱'), findsOneWidget);
    expect(find.text('witch@example.com'), findsOneWidget);
  });

  testWidgets('shows authentication errors without closing the dialog', (
    tester,
  ) async {
    final auth = _FakeAuthService()..signInError = Exception('bad login');
    await tester.pumpWidget(
      _app(
        MePage(
          authService: auth,
          profileService: _FakeProfileService(const AccountProfile.empty()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-login-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('login-email')),
      'witch@example.com',
    );
    await tester.enterText(find.byKey(const Key('login-password')), 'wrong');
    await tester.tap(find.byKey(const Key('login-submit-button')));
    await tester.pumpAndSettle();

    expect(find.text('Exception: bad login'), findsOneWidget);
    expect(find.byKey(const Key('login-email')), findsOneWidget);
  });

  testWidgets('restores an account and signs out', (tester) async {
    final auth = _FakeAuthService()..current = _account();
    await tester.pumpWidget(
      _app(
        MePage(
          authService: auth,
          profileService: _FakeProfileService(const AccountProfile.empty()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('metadata-name'), findsOneWidget);
    await tester.tap(find.byKey(const Key('logout-button')));
    await tester.pumpAndSettle();
    expect(auth.signOutCount, 1);
    expect(find.byKey(const Key('open-login-button')), findsOneWidget);
  });

  testWidgets('refreshes an expired session during restore', (tester) async {
    final auth = _FakeAuthService()
      ..current = AccountIdentity(
        id: 'user-1',
        email: 'old@example.com',
        usernameMetadata: '',
        expiresAt: 1,
      );
    await tester.pumpWidget(
      _app(
        MePage(
          authService: auth,
          profileService: _FakeProfileService(const AccountProfile.empty()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(auth.refreshCount, 1);
    expect(find.text('witch@example.com'), findsOneWidget);
  });
}

Widget _app(Widget child) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  home: Scaffold(body: child),
);

AccountIdentity _account() => const AccountIdentity(
  id: 'user-1',
  email: 'witch@example.com',
  usernameMetadata: 'metadata-name',
  expiresAt: null,
);

class _FakeAuthService implements AccountAuthService {
  final controller = StreamController<AccountIdentity?>.broadcast();
  AccountIdentity? current;
  Object? signInError;
  String? lastEmail;
  String? lastPassword;
  int refreshCount = 0;
  int signOutCount = 0;

  @override
  Stream<AccountIdentity?> get authChanges => controller.stream;

  @override
  AccountIdentity? get currentAccount => current;

  @override
  Future<AccountIdentity?> refreshSession() async {
    refreshCount++;
    current = _account();
    return current;
  }

  @override
  Future<AccountIdentity?> signIn({
    required String email,
    required String password,
  }) async {
    lastEmail = email;
    lastPassword = password;
    if (signInError != null) throw signInError!;
    current = _account();
    return current;
  }

  @override
  Future<void> signOut() async {
    signOutCount++;
    current = null;
  }

  @override
  Future<void> updatePassword(String password) async {}
}

class _FakeProfileService implements AccountProfileService {
  _FakeProfileService(this.profile);
  AccountProfile profile;

  @override
  Future<AccountProfile> load(String userId) async => profile;

  @override
  Future<void> save(String userId, AccountProfile profile) async {
    this.profile = profile;
  }
}
