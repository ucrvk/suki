import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suki/pages/account_settings_page.dart';
import 'package:suki/services/account_service.dart';

void main() {
  testWidgets('loads and saves profile with trimmed optional values', (
    tester,
  ) async {
    final profiles = _SettingsProfileService(
      const AccountProfile(
        username: '原名',
        qqName: 'QQ',
        avatarUrl: 'https://example.com/avatar.png',
      ),
    );
    await tester.pumpWidget(
      _app(
        AccountSettingsPage(
          account: _account,
          authService: _SettingsAuthService(),
          profileService: profiles,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '原名'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('profile-username')), '  新名  ');
    await tester.enterText(find.byKey(const Key('profile-qq-name')), '   ');
    await tester.enterText(find.byKey(const Key('profile-avatar-url')), '   ');
    await tester.tap(find.byKey(const Key('save-profile-button')));
    await tester.pumpAndSettle();

    expect(profiles.saved?.username, '新名');
    expect(profiles.saved?.qqName, isEmpty);
    expect(profiles.saved?.avatarUrl, isEmpty);
    expect(find.text('资料保存成功'), findsOneWidget);
  });

  testWidgets('requires a username', (tester) async {
    final profiles = _SettingsProfileService(const AccountProfile.empty());
    await tester.pumpWidget(
      _app(
        AccountSettingsPage(
          account: _account,
          authService: _SettingsAuthService(),
          profileService: profiles,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile-username')), ' ');
    await tester.tap(find.byKey(const Key('save-profile-button')));
    await tester.pump();

    expect(find.text('用户名不能为空'), findsOneWidget);
    expect(profiles.saved, isNull);
  });

  testWidgets('validates matching passwords and updates password', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _SettingsAuthService();
    await tester.pumpWidget(
      _app(
        AccountSettingsPage(
          account: _account,
          authService: auth,
          profileService: _SettingsProfileService(
            const AccountProfile(username: '用户', qqName: '', avatarUrl: ''),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('new-password')), 'one');
    await tester.enterText(find.byKey(const Key('confirm-password')), 'two');
    tester.testTextInput.hide();
    await tester.scrollUntilVisible(
      find.byKey(const Key('change-password-button')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('change-password-button')));
    await tester.pump();
    expect(find.text('两次输入的密码不一致'), findsOneWidget);
    expect(auth.updatedPassword, isNull);
    await tester.pump(const Duration(seconds: 5));

    await tester.enterText(find.byKey(const Key('confirm-password')), 'one');
    tester.testTextInput.hide();
    await tester.scrollUntilVisible(
      find.byKey(const Key('change-password-button')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('change-password-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(auth.updatedPassword, 'one');
  });
}

const _account = AccountIdentity(
  id: 'user-1',
  email: 'witch@example.com',
  usernameMetadata: 'metadata-name',
  expiresAt: null,
);

Widget _app(Widget child) =>
    MaterialApp(theme: ThemeData.dark(useMaterial3: true), home: child);

class _SettingsAuthService implements AccountAuthService {
  String? updatedPassword;

  @override
  Stream<AccountIdentity?> get authChanges => const Stream.empty();

  @override
  AccountIdentity? get currentAccount => _account;

  @override
  Future<AccountIdentity?> refreshSession() async => _account;

  @override
  Future<AccountIdentity?> signIn({
    required String email,
    required String password,
  }) async => _account;

  @override
  Future<void> signOut() async {}

  @override
  Future<void> updatePassword(String password) async {
    updatedPassword = password;
  }
}

class _SettingsProfileService implements AccountProfileService {
  _SettingsProfileService(this.profile);

  AccountProfile profile;
  AccountProfile? saved;

  @override
  Future<AccountProfile> load(String userId) async => profile;

  @override
  Future<void> save(String userId, AccountProfile profile) async {
    saved = profile;
    this.profile = profile;
  }
}
