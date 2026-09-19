import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suki/models/world_content_entry.dart';
import 'package:suki/pages/world_page.dart';
import 'package:suki/services/world_content_service.dart';

void main() {
  testWidgets('switches branches and keeps ending body hidden until tapped', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(WorldPage(dataSource: _WorldFixture())));
    await tester.pumpAndSettle();

    expect(find.text('纸樱'), findsOneWidget);
    expect(find.byKey(const Key('world-image-fallback')), findsWidgets);

    await tester.tap(find.text('世界观'));
    await tester.pumpAndSettle();
    expect(find.text('夜眠花'), findsOneWidget);

    await tester.tap(find.text('结局'));
    await tester.pumpAndSettle();
    expect(find.text('黎明之誓'), findsOneWidget);
    expect(find.text('结局正文不应预先显示'), findsNothing);

    await tester.tap(find.text('黎明之誓'));
    await tester.pumpAndSettle();
    expect(find.text('结局正文不应预先显示'), findsOneWidget);
    expect(find.byKey(const Key('world-detail-body')), findsOneWidget);
  });

  testWidgets('shows independent failure and retry state', (tester) async {
    await tester.pumpWidget(_testApp(WorldPage(dataSource: _FailingWorld())));
    await tester.pumpAndSettle();

    expect(find.text('内容加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('结局'));
    await tester.pumpAndSettle();
    expect(find.text('结局加载失败'), findsOneWidget);
  });
}

Widget _testApp(Widget child) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  home: Scaffold(body: child),
);

WorldContentEntry _codex(WorldContentKind kind, String title) {
  return WorldContentEntry(
    id: '${kind.name}-$title',
    kind: kind,
    title: title,
    subtitle: '副标题',
    imageUrl: '',
    imageUrl2: '',
    tags: const ['标签'],
    body: '详细内容',
    sort: 1,
    createdAt: DateTime(2026),
    script: '',
  );
}

WorldContentEntry _ending() => WorldContentEntry(
  id: 'ending-1',
  kind: WorldContentKind.ending,
  title: '黎明之誓',
  subtitle: '结局副标题',
  imageUrl: '',
  imageUrl2: '',
  tags: const ['结局'],
  body: '结局正文不应预先显示',
  sort: 1,
  createdAt: DateTime(2026),
  script: '夜眠花',
);

class _WorldFixture implements WorldDataSource {
  final codex = WorldContentSnapshot(
    entries: [
      _codex(WorldContentKind.witch, '纸樱'),
      _codex(WorldContentKind.lore, '夜眠花'),
    ],
    fetchedAt: DateTime(2026),
  );
  final endings = WorldContentSnapshot(
    entries: [_ending()],
    fetchedAt: DateTime(2026),
  );

  @override
  Future<WorldContentSnapshot?> loadCachedCodex() async => null;

  @override
  Future<WorldContentSnapshot?> loadCachedEndings() async => null;

  @override
  Future<WorldContentSnapshot> refreshCodex() async => codex;

  @override
  Future<WorldContentSnapshot> refreshEndings() async => endings;
}

class _FailingWorld implements WorldDataSource {
  @override
  Future<WorldContentSnapshot?> loadCachedCodex() async => null;

  @override
  Future<WorldContentSnapshot?> loadCachedEndings() async => null;

  @override
  Future<WorldContentSnapshot> refreshCodex() =>
      Future.error(Exception('codex offline'));

  @override
  Future<WorldContentSnapshot> refreshEndings() =>
      Future.error(Exception('endings offline'));
}
