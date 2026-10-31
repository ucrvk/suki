import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:suki/pages/me_page.dart';
import 'package:suki/services/app_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
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
      httpClient: MockClient((_) async => http.Response('[]', 200)),
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  Future<void> openPage(WidgetTester tester, AppUpdateRemote remote) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MePage(
          updateService: AppUpdateService(
            remote: remote,
            currentVersion: () async => '2.0.3+1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('通知设置'), findsNothing);
    expect(find.text('显示排队栏'), findsOneWidget);
    await tester.tap(find.byKey(const Key('check-update-button')));
    await tester.pumpAndSettle();
  }

  testWidgets('shows a 2.x update and a release link', (tester) async {
    await openPage(tester, _Remote(['v3.9.0', 'v2.0.4']));
    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.textContaining('最新版本 v2.0.4'), findsOneWidget);
    expect(find.byKey(const Key('open-latest-release-button')), findsOneWidget);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本'), findsNothing);
    expect(find.textContaining('有新版本 v2.0.4'), findsOneWidget);
  });
  testWidgets('does not offer a v3 update', (tester) async {
    await openPage(tester, _Remote(['v3.9.0', 'v2.0.3']));
    expect(find.text('发现新版本'), findsNothing);
    expect(find.text('已是最新版本 v2.0.3+1'), findsOneWidget);
  });
  testWidgets('shows failure and allows another check', (tester) async {
    final remote = _Remote([], fail: true);
    await openPage(tester, remote);
    expect(find.text('检查更新失败，请检查网络后重试'), findsOneWidget);
    remote.fail = false;
    remote.tags.add('v2.0.4');
    await tester.tap(find.byKey(const Key('check-update-button')));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本'), findsOneWidget);
  });
}

class _Remote implements AppUpdateRemote {
  _Remote(this.tags, {this.fail = false});
  final List<String> tags;
  bool fail;
  @override
  Future<List<String>> fetchTagNames() async {
    if (fail) throw const AppUpdateException('offline');
    return tags;
  }
}
