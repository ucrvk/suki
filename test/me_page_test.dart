import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:suki/pages/me_page.dart';
import 'package:suki/services/account_service.dart';
import 'package:suki/services/app_update_service.dart';
import 'package:suki/services/bgm_controller.dart';
import 'package:suki/services/spoiler_mode_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  testWidgets('toggles the spoiler mode switch', (tester) async {
    final store = _FakeSpoilerModeStore();
    await tester.pumpWidget(
      _app(
        MePage(
          authService: _FakeAuthService(),
          profileService: _FakeProfileService(const AccountProfile.empty()),
          spoilerModeStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('spoiler-mode-switch')), findsOneWidget);
    expect(store.value, isFalse);

    await tester.tap(find.byKey(const Key('spoiler-mode-switch')));
    await tester.pumpAndSettle();

    expect(store.value, isTrue);
    expect(store.setEnabledCalls, 1);

    await tester.tap(find.byKey(const Key('spoiler-mode-switch')));
    await tester.pumpAndSettle();

    expect(store.value, isFalse);
    expect(store.setEnabledCalls, 2);
  });

  testWidgets('toggles the background music switch', (tester) async {
    final bgm = _FakeBgmController();
    await tester.pumpWidget(
      _app(
        MePage(
          authService: _FakeAuthService(),
          profileService: _FakeProfileService(const AccountProfile.empty()),
          bgmController: bgm,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bgm-switch')), findsOneWidget);
    expect(bgm.value, isFalse);

    await tester.tap(find.byKey(const Key('bgm-switch')));
    await tester.pumpAndSettle();

    expect(bgm.value, isTrue);
    expect(bgm.setEnabledCalls, 1);

    await tester.tap(find.byKey(const Key('bgm-switch')));
    await tester.pumpAndSettle();

    expect(bgm.value, isFalse);
    expect(bgm.setEnabledCalls, 2);
  });

  testWidgets('hides the background music switch without a controller', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        MePage(
          authService: _FakeAuthService(),
          profileService: _FakeProfileService(const AccountProfile.empty()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bgm-switch')), findsNothing);
  });

  testWidgets('shows register next to login and validates the form', (
    tester,
  ) async {
    final auth = _FakeAuthService();
    await tester.pumpWidget(
      _app(
        MePage(
          authService: auth,
          profileService: _FakeProfileService(const AccountProfile.empty()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open-login-button')), findsOneWidget);
    expect(find.byKey(const Key('open-register-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-register-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('register-username')), findsOneWidget);
    expect(find.byKey(const Key('register-confirm-password')), findsOneWidget);

    // 空字段
    await tester.tap(find.byKey(const Key('register-submit-button')));
    await tester.pumpAndSettle();
    expect(find.text('请输入用户名、邮箱和密码'), findsOneWidget);
    expect(auth.signUpCount, 0);
    await _dismissSnackBars(tester);

    // 密码太短
    await _fillRegisterForm(tester, password: '12345');
    await tester.tap(find.byKey(const Key('register-submit-button')));
    await tester.pumpAndSettle();
    expect(find.text('密码至少 6 位'), findsOneWidget);
    expect(auth.signUpCount, 0);
    await _dismissSnackBars(tester);

    // 两次密码不一致
    await _fillRegisterForm(tester, password: '123456', confirm: '123457');
    await tester.tap(find.byKey(const Key('register-submit-button')));
    await tester.pumpAndSettle();
    expect(find.text('两次输入的密码不一致'), findsOneWidget);
    expect(auth.signUpCount, 0);
  });

  testWidgets('signs up and asks for email confirmation', (tester) async {
    // 默认 fake 返回 null：对应项目开启了 Confirm email。
    final auth = _FakeAuthService();
    await tester.pumpWidget(
      _app(
        MePage(
          authService: auth,
          profileService: _FakeProfileService(const AccountProfile.empty()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-register-button')));
    await tester.pumpAndSettle();
    await _fillRegisterForm(tester);
    await tester.tap(find.byKey(const Key('register-submit-button')));
    await tester.pumpAndSettle();

    expect(auth.signUpCount, 1);
    expect(auth.signUpUsername, 'uckhhh');
    expect(auth.signUpEmail, 'ojow@wenwen12305.top');
    expect(auth.signUpPassword, '11qqaa');
    expect(find.text('注册成功，请到邮箱点击确认链接后再登录'), findsOneWidget);
    expect(find.byKey(const Key('register-email')), findsNothing);
    expect(find.byKey(const Key('open-login-button')), findsOneWidget);

    // 确认邮件之后回登录框，邮箱已经回填。
    await _dismissSnackBars(tester);
    await tester.tap(find.byKey(const Key('open-login-button')));
    await tester.pumpAndSettle();
    final email = tester.widget<TextField>(
      find.byKey(const Key('login-email')),
    );
    expect(email.controller!.text, 'ojow@wenwen12305.top');
  });

  testWidgets('logs in right away when sign up returns a session', (
    tester,
  ) async {
    final auth = _FakeAuthService()..signUpResult = _account();
    await tester.pumpWidget(
      _app(
        MePage(
          authService: auth,
          profileService: _FakeProfileService(const AccountProfile.empty()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-register-button')));
    await tester.pumpAndSettle();
    await _fillRegisterForm(tester);
    await tester.tap(find.byKey(const Key('register-submit-button')));
    await tester.pumpAndSettle();

    expect(find.text('注册成功'), findsOneWidget);
    expect(find.byKey(const Key('open-login-button')), findsNothing);
    expect(find.text('metadata-name'), findsOneWidget);
  });

  testWidgets('keeps the register dialog open when sign up fails', (
    tester,
  ) async {
    final auth = _FakeAuthService()
      ..signUpError = const AuthException(
        'User already registered',
        statusCode: '422',
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

    await tester.tap(find.byKey(const Key('open-register-button')));
    await tester.pumpAndSettle();
    await _fillRegisterForm(tester);
    await tester.tap(find.byKey(const Key('register-submit-button')));
    await tester.pumpAndSettle();

    expect(find.text('该邮箱已注册，请直接登录'), findsOneWidget);
    expect(find.byKey(const Key('register-email')), findsOneWidget);
  });

  testWidgets('checks for updates and offers the newer release', (
    tester,
  ) async {
    _mockAppVersion('3.0.1', '1');
    final service = AppUpdateService(
      remote: _FakeUpdateRemote(const ['v3.0.1', 'v3.0.2']),
      currentVersion: () async => '3.0.1+1',
    );
    await tester.pumpWidget(_app(_mePage(updateService: service)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('check-update-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('check-update-button')));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.textContaining('最新版本 v3.0.2'), findsOneWidget);

    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本'), findsNothing);
    // 版本号一栏保留提示。
    expect(find.textContaining('有新版本 v3.0.2'), findsOneWidget);
  });

  testWidgets('reports the app is already up to date', (tester) async {
    _mockAppVersion('3.0.1', '1');
    final service = AppUpdateService(
      remote: _FakeUpdateRemote(const ['v3.0.1', 'v3.0.1-rc.3']),
      currentVersion: () async => '3.0.1+1',
    );
    await tester.pumpWidget(_app(_mePage(updateService: service)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('check-update-button')));
    await tester.pumpAndSettle();

    expect(find.text('已是最新版本 v3.0.1+1'), findsOneWidget);
    expect(find.text('发现新版本'), findsNothing);
  });

  testWidgets('surfaces a failed update check', (tester) async {
    final service = AppUpdateService(
      remote: _FakeUpdateRemote(const [], error: Exception('offline')),
      currentVersion: () async => '3.0.1+1',
    );
    await tester.pumpWidget(_app(_mePage(updateService: service)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('check-update-button')));
    await tester.pumpAndSettle();

    expect(find.text('检查更新失败，请检查网络后重试'), findsOneWidget);
  });

  testWidgets(
    'shows the update button on Android and desktop',
    (tester) async {
      await tester.pumpWidget(_app(_mePage()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('check-update-button')), findsOneWidget);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.linux,
      TargetPlatform.windows,
    }),
  );

  testWidgets('hides the update button on unsupported platforms', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_mePage()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('check-update-button')), findsNothing);
    expect(find.byKey(const Key('github-link-button')), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}

/// 填入注册表单，默认用与需求一致的那组示例数据。
Future<void> _fillRegisterForm(
  WidgetTester tester, {
  String username = 'uckhhh',
  String email = 'ojow@wenwen12305.top',
  String password = '11qqaa',
  String? confirm,
}) async {
  await tester.enterText(find.byKey(const Key('register-username')), username);
  await tester.enterText(find.byKey(const Key('register-email')), email);
  await tester.enterText(find.byKey(const Key('register-password')), password);
  await tester.enterText(
    find.byKey(const Key('register-confirm-password')),
    confirm ?? password,
  );
}

/// 等当前 SnackBar 自动消失，避免后续提示排队挡住断言。
Future<void> _dismissSnackBars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

MePage _mePage({AppUpdateService? updateService}) => MePage(
  authService: _FakeAuthService(),
  profileService: _FakeProfileService(const AccountProfile.empty()),
  updateService: updateService,
);

/// 让 `_loadAppVersion` 拿到确定的版本号。
void _mockAppVersion(String version, String build) {
  PackageInfo.setMockInitialValues(
    appName: 'suki',
    packageName: 'com.example.suki',
    version: version,
    buildNumber: build,
    buildSignature: '',
  );
}

class _FakeUpdateRemote implements AppUpdateRemote {
  _FakeUpdateRemote(this.tags, {this.error});

  final List<String> tags;
  final Object? error;

  @override
  Future<List<String>> fetchTagNames() async {
    final failure = error;
    if (failure != null) throw failure;
    return tags;
  }
}

class _FakeBgmController extends ChangeNotifier implements BgmController {
  bool _enabled = false;
  int setEnabledCalls = 0;

  @override
  bool get value => _enabled;

  @override
  Future<void> setEnabled(bool enabled) async {
    setEnabledCalls++;
    _enabled = enabled;
    notifyListeners();
  }

  @override
  Future<void> resumeIfNeeded() async {}
}

class _FakeSpoilerModeStore extends ChangeNotifier implements SpoilerModeStore {
  bool _enabled = false;
  int setEnabledCalls = 0;

  @override
  bool get value => _enabled;

  @override
  Future<void> setEnabled(bool enabled) async {
    setEnabledCalls++;
    _enabled = enabled;
    notifyListeners();
  }
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

  // 注册相关：默认模拟「已开启邮箱确认」（返回 null、不建立会话）。
  Object? signUpError;
  AccountIdentity? signUpResult;
  String? signUpEmail;
  String? signUpPassword;
  String? signUpUsername;
  int signUpCount = 0;

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
  Future<AccountIdentity?> signUp({
    required String email,
    required String password,
    String? username,
  }) async {
    signUpCount++;
    signUpEmail = email;
    signUpPassword = password;
    signUpUsername = username;
    if (signUpError != null) throw signUpError!;
    final result = signUpResult;
    if (result != null) current = result;
    return result;
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
