import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:suki/app_shell.dart';
import 'package:suki/app_theme.dart';
import 'package:suki/widgets/responsive_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'suki',
      packageName: 'test.suki',
      version: '2.0.4',
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

  tearDownAll(() {
    Supabase.instance.dispose();
    AppShell.tabIndexNotifier.value = 0;
    AppShell.tabReselectNotifier.value = null;
  });

  Future<void> pumpShell(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const AppShell(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('wide shell shows the rail and removes the top bars', (
    tester,
  ) async {
    await pumpShell(tester, const Size(1200, 900));

    expect(find.byKey(ResponsiveShell.railKey), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('猫生重开'), findsOneWidget);
    expect(find.text('猫王争霸'), findsOneWidget);

    // 宽屏下所有页面的顶栏都不显示。
    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets('narrow shell keeps the bottom bar and page top bars', (
    tester,
  ) async {
    await pumpShell(tester, const Size(400, 900));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(ResponsiveShell.railKey), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
    // 窄屏没有左栏，宣传链接仍在预约页顶栏里。
    expect(find.text('猫生重开'), findsOneWidget);
    expect(find.text('猫王争霸'), findsOneWidget);
  });

  testWidgets('switching width keeps the same page state', (tester) async {
    await pumpShell(tester, const Size(1200, 900));
    expect(find.byKey(ResponsiveShell.railKey), findsOneWidget);

    tester.view.physicalSize = const Size(400, 900);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a very short window falls back to the bottom bar', (
    tester,
  ) async {
    await pumpShell(tester, const Size(1200, 450));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(ResponsiveShell.railKey), findsNothing);
    // 回到常规布局后页面顶栏也回来了。
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('rail shortcuts open links without switching tabs', (
    tester,
  ) async {
    await pumpShell(tester, const Size(1200, 900));
    expect(AppShell.tabIndexNotifier.value, AppShell.bookingTabIndex());

    // 普通导航项会切换页面。
    await tester.tap(find.text('排班'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(AppShell.tabIndexNotifier.value, AppShell.scheduleTabIndex());

    // 宣传入口只跳转浏览器，不改变当前导航项。
    await tester.tap(find.text('猫生重开'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(AppShell.tabIndexNotifier.value, AppShell.scheduleTabIndex());
    expect(tester.takeException(), isNull);
  });
}
