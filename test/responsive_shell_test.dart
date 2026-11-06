import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suki/app_theme.dart';
import 'package:suki/widgets/responsive_shell.dart';

const _destinations = [
  ShellDestination(icon: Icons.calendar_month, label: '预约'),
  ShellDestination(icon: Icons.event_note_outlined, label: '排班'),
  ShellDestination(icon: Icons.menu_book_outlined, label: '介绍'),
  ShellDestination(icon: Icons.person, label: '我'),
];

const _fullDestinations = [
  ShellDestination(icon: Icons.format_list_numbered_rounded, label: '排队'),
  ShellDestination(icon: Icons.calendar_month, label: '预约'),
  ShellDestination(icon: Icons.event_note_outlined, label: '排班'),
  ShellDestination(icon: Icons.menu_book_outlined, label: '介绍'),
  ShellDestination(icon: Icons.reviews_outlined, label: '评价'),
  ShellDestination(icon: Icons.forum_outlined, label: '留言'),
  ShellDestination(icon: Icons.photo_library_outlined, label: '照片墙'),
  ShellDestination(icon: Icons.person, label: '我'),
  ShellDestination(icon: Icons.restart_alt_rounded, label: '猫生重开'),
  ShellDestination(icon: Icons.emoji_events_outlined, label: '猫王争霸'),
];

/// 与 AppShell 左栏底部一致：只放退出登录。
Widget _railTrailing() {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: IconButton(onPressed: () {}, icon: const Icon(Icons.logout_rounded)),
  );
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required Size size,
  List<ShellDestination> destinations = _destinations,
  Widget? body,
  Widget? trailing,
  ValueChanged<int>? onSelected,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: ResponsiveShell(
        body: body ?? const Center(child: Text('body')),
        selectedIndex: 0,
        onDestinationSelected: onSelected ?? (_) {},
        destinations: destinations,
        railTrailing: trailing,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

double? _railIconSize(WidgetTester tester, IconData icon) {
  return tester.widget<Icon>(find.byIcon(icon)).size;
}

void main() {
  testWidgets('wide and tall screen uses the big rail', (tester) async {
    await _pumpShell(tester, size: const Size(1200, 900));

    expect(find.byKey(ResponsiveShell.railKey), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    expect(_railIconSize(tester, Icons.calendar_month), 26);
  });

  testWidgets('wide but shorter screen uses the small rail', (tester) async {
    await _pumpShell(tester, size: const Size(1200, 700));

    expect(find.byKey(ResponsiveShell.railKey), findsOneWidget);
    expect(_railIconSize(tester, Icons.calendar_month), 20);
  });

  testWidgets('the rail scrolls when it still does not fit', (tester) async {
    await _pumpShell(
      tester,
      size: const Size(1200, 520),
      destinations: _fullDestinations,
      trailing: _railTrailing(),
    );

    expect(find.byKey(ResponsiveShell.railKey), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('猫王争霸'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('falls back to the bottom bar when the window is too short', (
    tester,
  ) async {
    await _pumpShell(tester, size: const Size(1200, 450));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(ResponsiveShell.railKey), findsNothing);
  });

  testWidgets('narrow screen keeps the bottom bar', (tester) async {
    await _pumpShell(tester, size: const Size(400, 900));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(ResponsiveShell.railKey), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('switches layouts across the 840 width breakpoint', (
    tester,
  ) async {
    await _pumpShell(tester, size: const Size(839, 900));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(ResponsiveShell.railKey), findsNothing);

    tester.view.physicalSize = const Size(840, 900);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(ResponsiveShell.railKey), findsOneWidget);
  });

  testWidgets('keeps page state when switching between rail and bar', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      size: const Size(400, 900),
      body: const _TextFieldBody(),
    );
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    expect(find.text('hello'), findsOneWidget);

    tester.view.physicalSize = const Size(1200, 900);
    await tester.pumpAndSettle();
    expect(find.byKey(ResponsiveShell.railKey), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);

    tester.view.physicalSize = const Size(1200, 450);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('reports destination taps in both layouts', (tester) async {
    final taps = <int>[];
    await _pumpShell(tester, size: const Size(1200, 900), onSelected: taps.add);

    await tester.tap(find.text('排班'));
    await tester.pumpAndSettle();
    expect(taps, [1]);

    taps.clear();
    tester.view.physicalSize = const Size(400, 900);
    await tester.pumpAndSettle();
    await tester.tap(find.text('排班'));
    await tester.pumpAndSettle();
    expect(taps, [1]);
  });

  testWidgets('exposes the wide flag to pages through ShellScope', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      size: const Size(1200, 900),
      body: Builder(
        builder: (context) =>
            Text(ShellScope.isWide(context) ? 'wide' : 'narrow'),
      ),
    );
    expect(find.text('wide'), findsOneWidget);

    tester.view.physicalSize = const Size(400, 900);
    await tester.pumpAndSettle();
    expect(find.text('narrow'), findsOneWidget);

    tester.view.physicalSize = const Size(1200, 450);
    await tester.pumpAndSettle();
    expect(find.text('narrow'), findsOneWidget);
  });

  testWidgets('all destinations fit on a short screen', (tester) async {
    await _pumpShell(
      tester,
      size: const Size(1024, 600),
      destinations: _fullDestinations,
      trailing: _railTrailing(),
    );

    expect(find.byKey(ResponsiveShell.railKey), findsOneWidget);
    expect(find.text('猫生重开'), findsOneWidget);
    expect(find.text('猫王争霸'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('day mode fills the frame with a lighter pink knockout', (
    tester,
  ) async {
    await _pumpShell(tester, size: const Size(1200, 900));

    final frame = tester.widget<Container>(
      find.byKey(ResponsiveShell.railLogoKey),
    );
    final decoration = frame.decoration! as BoxDecoration;
    final image = tester.widget<Image>(find.byType(Image));

    // 颜色由反相蒙板提供（中间镂空），容器只负责圆角裁剪。
    expect(decoration.color, isNull);
    expect(decoration.borderRadius, BorderRadius.circular(17));
    expect(frame.clipBehavior, Clip.antiAlias);
    expect(
      (image.image as AssetImage).assetName,
      'assets/icon_board_inverse.png',
    );
    expect(
      image.color,
      Color.lerp(const Color(0xFFD31F7C), Colors.white, 0.72),
    );
  });

  testWidgets('night mode uses the same knockout with a lighter pink', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      size: const Size(1200, 900),
      theme: buildAppTheme(Brightness.dark),
    );

    final frame = tester.widget<Container>(
      find.byKey(ResponsiveShell.railLogoKey),
    );
    final decoration = frame.decoration! as BoxDecoration;
    final image = tester.widget<Image>(find.byType(Image));
    final nightColor = Color.lerp(const Color(0xFFD31F7C), Colors.white, 0.12);
    final dayColor = Color.lerp(const Color(0xFFD31F7C), Colors.white, 0.72);

    expect(decoration.color, isNull);
    expect(frame.clipBehavior, Clip.antiAlias);
    expect(
      (image.image as AssetImage).assetName,
      'assets/icon_board_inverse.png',
    );
    expect(image.color, nightColor);
    // 夜间比白天更深。
    expect(
      nightColor!.computeLuminance(),
      lessThan(dayColor!.computeLuminance()),
    );
  });

  testWidgets('keeps the logo at the top of the rail', (tester) async {
    await _pumpShell(
      tester,
      size: const Size(1024, 600),
      destinations: _fullDestinations,
      trailing: _railTrailing(),
    );

    final logoTop = tester.getTopLeft(find.byType(Image)).dy;
    expect(logoTop, lessThan(20));
  });
}

class _TextFieldBody extends StatelessWidget {
  const _TextFieldBody();

  @override
  Widget build(BuildContext context) {
    return const Center(child: TextField());
  }
}
